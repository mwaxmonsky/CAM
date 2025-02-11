module modal_aerosol_properties_mod
  use shr_kind_mod, only: r8 => shr_kind_r8
  use physconst, only: pi
  use aerosol_properties_mod, only: aerosol_properties, aero_name_len
  use rad_constituents, only: rad_cnst_get_info, rad_cnst_get_mode_props, rad_cnst_get_aer_props

  implicit none

  private

  public :: modal_aerosol_properties

  type, extends(aerosol_properties) :: modal_aerosol_properties
     private
     real(r8), allocatable :: exp45logsig_(:)
     real(r8), allocatable :: voltonumblo_(:)
     real(r8), allocatable :: voltonumbhi_(:)
     integer,  allocatable :: sulfate_mode_ndxs_(:)
     integer,  allocatable :: dust_mode_ndxs_(:)
     integer,  allocatable :: ssalt_mode_ndxs_(:)
     integer,  allocatable :: ammon_mode_ndxs_(:)
     integer,  allocatable :: nitrate_mode_ndxs_(:)
     integer,  allocatable :: msa_mode_ndxs_(:)
     integer,  allocatable :: bcarbon_mode_ndxs_(:,:)
     integer,  allocatable :: porganic_mode_ndxs_(:,:)
     integer,  allocatable :: sorganic_mode_ndxs_(:,:)
     integer :: num_soa_ = 0
     integer :: num_poa_ = 0
     integer :: num_bc_ = 0
   contains
     procedure :: number_transported
     procedure :: get
     procedure :: amcube
     procedure :: actfracs
     procedure :: num_names
     procedure :: mmr_names
     procedure :: amb_num_name
     procedure :: amb_mmr_name
     procedure :: species_type
     procedure :: icenuc_updates_num
     procedure :: icenuc_updates_mmr
     procedure :: apply_number_limits
     procedure :: hetfrz_species
     procedure :: optics_params
     procedure :: nbins_rlist
     procedure :: nspecies_per_bin_rlist
     procedure :: alogsig_rlist
     procedure :: soluble
     procedure :: min_mass_mean_rad
     procedure :: bin_name
     procedure :: scav_diam
     procedure :: resuspension_resize
     procedure :: rebin_bulk_fluxes
     procedure :: hydrophilic

     final :: destructor
  end type modal_aerosol_properties

  interface modal_aerosol_properties
     procedure :: constructor
  end interface modal_aerosol_properties

  logical, parameter :: debug = .false.

contains

  !------------------------------------------------------------------------------
  !------------------------------------------------------------------------------
  function constructor() result(newobj)

    type(modal_aerosol_properties), pointer :: newobj

    integer :: l, m, nmodes, ncnst_tot, mm
    real(r8) :: dgnumlo
    real(r8) :: dgnumhi
    integer,allocatable :: nspecies(:)
    real(r8),allocatable :: sigmag(:)
    real(r8),allocatable :: alogsig(:)
    real(r8),allocatable :: f1(:)
    real(r8),allocatable :: f2(:)
    integer :: ierr

    character(len=aero_name_len) :: spectype

    integer :: npoa, nsoa, nbc

    allocate(newobj,stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if

    call rad_cnst_get_info(0, nmodes=nmodes)

    allocate(nspecies(nmodes),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(alogsig(nmodes),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate( f1(nmodes),stat=ierr )
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate( f2(nmodes),stat=ierr )
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if

    allocate(sigmag(nmodes),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%exp45logsig_(nmodes),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%voltonumblo_(nmodes),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%voltonumbhi_(nmodes),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if

    ncnst_tot = 0

    do m = 1, nmodes
       call rad_cnst_get_info(0, m, nspec=nspecies(m))

       ncnst_tot =  ncnst_tot + nspecies(m) + 1

       call rad_cnst_get_mode_props(0, m, sigmag=sigmag(m), &
                                    dgnumhi=dgnumhi, dgnumlo=dgnumlo )

       alogsig(m) = log(sigmag(m))

       newobj%exp45logsig_(m) = exp(4.5_r8*alogsig(m)*alogsig(m))

       f1(m) = 0.5_r8*exp(2.5_r8*alogsig(m)*alogsig(m))
       f2(m) = 1._r8 + 0.25_r8*alogsig(m)

       newobj%voltonumblo_(m) = 1._r8 / ( (pi/6._r8)* &
            (dgnumlo**3._r8)*exp(4.5_r8*alogsig(m)**2._r8) )
       newobj%voltonumbhi_(m) = 1._r8 / ( (pi/6._r8)* &
            (dgnumhi**3._r8)*exp(4.5_r8*alogsig(m)**2._r8) )

    end do

    call newobj%initialize(nmodes,ncnst_tot,nspecies,nspecies,alogsig,f1,f2,ierr)

    npoa = 0
    nsoa = 0
    nbc = 0

    m = 1
    do l = 1,newobj%nspecies(m)
       mm = newobj%indexer(m,l)
       call newobj%species_type(m, l, spectype)
       select case ( trim(spectype) )
       case('p-organic')
          npoa = npoa + 1
       case('s-organic')
          nsoa = nsoa + 1
       case('black-c')
          nbc = nbc + 1
       end select
    end do

    newobj%num_soa_ = nsoa
    newobj%num_poa_ = npoa
    newobj%num_bc_ = nbc

    allocate(newobj%sulfate_mode_ndxs_(newobj%nbins()),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%dust_mode_ndxs_(newobj%nbins()),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%ssalt_mode_ndxs_(newobj%nbins()),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%ammon_mode_ndxs_(newobj%nbins()),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%nitrate_mode_ndxs_(newobj%nbins()),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%msa_mode_ndxs_(newobj%nbins()),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if

    newobj%sulfate_mode_ndxs_ = 0
    newobj%dust_mode_ndxs_ = 0
    newobj%ssalt_mode_ndxs_ = 0
    newobj%ammon_mode_ndxs_ = 0
    newobj%nitrate_mode_ndxs_ = 0
    newobj%msa_mode_ndxs_ = 0

    allocate(newobj%porganic_mode_ndxs_(newobj%nbins(),npoa),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%sorganic_mode_ndxs_(newobj%nbins(),nsoa),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    allocate(newobj%bcarbon_mode_ndxs_(newobj%nbins(),nbc),stat=ierr)
    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if

    newobj%porganic_mode_ndxs_ = 0._r8
    newobj%sorganic_mode_ndxs_ = 0._r8
    newobj%bcarbon_mode_ndxs_ = 0._r8

    do m = 1,newobj%nbins()
       npoa = 0
       nsoa = 0
       nbc = 0

       do l = 1,newobj%nspecies(m)
          mm = newobj%indexer(m,l)
          call newobj%species_type(m, l, spectype)

          select case ( trim(spectype) )
          case('sulfate')
             newobj%sulfate_mode_ndxs_(m) = mm
          case('dust')
             newobj%dust_mode_ndxs_(m) = mm
          case('nitrate')
             newobj%nitrate_mode_ndxs_(m) = mm
          case('ammonium')
             newobj%ammon_mode_ndxs_(m) = mm
          case('seasalt')
             newobj%ssalt_mode_ndxs_(m) = mm
          case('msa')
             newobj%msa_mode_ndxs_(m) = mm
          case('p-organic')
             npoa = npoa + 1
             newobj%porganic_mode_ndxs_(m,npoa)  = mm
          case('s-organic')
             nsoa = nsoa + 1
             newobj%sorganic_mode_ndxs_(m,nsoa)  = mm
          case('black-c')
             nbc = nbc + 1
             newobj%bcarbon_mode_ndxs_(m,nbc)  = mm
          end select

       end do
    end do

    if( ierr /= 0 ) then
       nullify(newobj)
       return
    end if
    deallocate(nspecies)
    deallocate(alogsig)
    deallocate(sigmag)
    deallocate(f1)
    deallocate(f2)

  end function constructor

  !------------------------------------------------------------------------------
  !------------------------------------------------------------------------------
  subroutine destructor(self)
    type(modal_aerosol_properties), intent(inout) :: self

    if (allocated(self%exp45logsig_)) then
       deallocate(self%exp45logsig_)
    end if
    if (allocated(self%voltonumblo_)) then
       deallocate(self%voltonumblo_)
    end if
    if (allocated(self%voltonumbhi_)) then
       deallocate(self%voltonumbhi_)
    end if

    if (allocated(self%sulfate_mode_ndxs_)) then
       deallocate(self%sulfate_mode_ndxs_)
    end if
    if (allocated(self%dust_mode_ndxs_)) then
       deallocate(self%dust_mode_ndxs_)
    end if
    if (allocated(self%ssalt_mode_ndxs_)) then
       deallocate(self%ssalt_mode_ndxs_)
    end if
    if (allocated(self%ammon_mode_ndxs_)) then
       deallocate(self%ammon_mode_ndxs_)
    end if
    if (allocated(self%nitrate_mode_ndxs_)) then
       deallocate(self%nitrate_mode_ndxs_)
    end if
    if (allocated(self%msa_mode_ndxs_)) then
       deallocate(self%msa_mode_ndxs_)
    end if
    if (allocated(self%porganic_mode_ndxs_)) then
       deallocate(self%porganic_mode_ndxs_)
    end if
    if (allocated(self%sorganic_mode_ndxs_)) then
       deallocate(self%sorganic_mode_ndxs_)
    end if
    if (allocated(self%bcarbon_mode_ndxs_)) then
       deallocate(self%bcarbon_mode_ndxs_)
    end if

    call self%final()

  end subroutine destructor

  !------------------------------------------------------------------------------
  ! returns number of transported aerosol constituents
  !------------------------------------------------------------------------------
  integer function number_transported(self)
    class(modal_aerosol_properties), intent(in) :: self
    ! to be implemented later
    number_transported = -1
  end function number_transported

  !------------------------------------------------------------------------
  ! returns aerosol properties:
  !  density
  !  hygroscopicity
  !  species type
  !  species name
  !  short wave species refractive indices
  !  long wave species refractive indices
  !  species morphology
  !------------------------------------------------------------------------
  subroutine get(self, bin_ndx, species_ndx, list_ndx, density, hygro, &
                 spectype, specname, specmorph, refindex_sw, refindex_lw)

    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx             ! bin index
    integer, intent(in) :: species_ndx         ! species index
    integer, optional, intent(in) :: list_ndx  ! climate or a diagnostic list number
    real(r8), optional, intent(out) :: density ! density (kg/m3)
    real(r8), optional, intent(out) :: hygro   ! hygroscopicity
    character(len=*), optional, intent(out) :: spectype  ! species type
    character(len=*), optional, intent(out) :: specname  ! species name
    character(len=*), optional, intent(out) :: specmorph ! species morphology
    complex(r8), pointer, optional, intent(out) :: refindex_sw(:) ! short wave species refractive indices
    complex(r8), pointer, optional, intent(out) :: refindex_lw(:) ! long wave species refractive indices

    integer :: ilist

    if (present(list_ndx)) then
       ilist = list_ndx
    else
       ilist = 0
    end if

    call rad_cnst_get_aer_props(ilist, bin_ndx, species_ndx, &
                                density_aer=density, hygro_aer=hygro, spectype=spectype, &
                                refindex_aer_sw=refindex_sw, refindex_aer_lw=refindex_lw)

    if (present(specname)) then
       call rad_cnst_get_info(ilist, bin_ndx, species_ndx, spec_name=specname)
    end if

    if (present(specmorph)) then
       specmorph = 'UNKNOWN'
    end if

  end subroutine get

  !------------------------------------------------------------------------
  ! returns optics type and table parameters
  !------------------------------------------------------------------------
  subroutine optics_params(self, list_ndx, bin_ndx, opticstype, extpsw, abspsw, asmpsw, absplw, &
       refrtabsw, refitabsw, refrtablw, refitablw, ncoef, prefr, prefi, sw_hygro_ext_wtp, &
       sw_hygro_ssa_wtp, sw_hygro_asm_wtp, lw_hygro_ext_wtp, wgtpct, nwtp, &
       sw_hygro_coreshell_ext, sw_hygro_coreshell_ssa, sw_hygro_coreshell_asm, lw_hygro_coreshell_ext, &
       corefrac, bcdust, kap, relh, nfrac, nbcdust, nkap, nrelh )

    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx             ! bin index
    integer, intent(in) :: list_ndx            ! rad climate/diags list

    character(len=*), optional, intent(out) :: opticstype

    ! refactive index table parameters
    real(r8),  optional, pointer     :: extpsw(:,:,:,:) ! short wave specific extinction
    real(r8),  optional, pointer     :: abspsw(:,:,:,:) ! short wave specific absorption
    real(r8),  optional, pointer     :: asmpsw(:,:,:,:) ! short wave asymmetry factor
    real(r8),  optional, pointer     :: absplw(:,:,:,:) ! long wave specific absorption
    real(r8),  optional, pointer     :: refrtabsw(:,:)  ! table of short wave real refractive indices for aerosols
    real(r8),  optional, pointer     :: refitabsw(:,:)  ! table of short wave imaginary refractive indices for aerosols
    real(r8),  optional, pointer     :: refrtablw(:,:)  ! table of long wave real refractive indices for aerosols
    real(r8),  optional, pointer     :: refitablw(:,:)  ! table of long wave imaginary refractive indices for aerosols
    integer,   optional, intent(out) :: ncoef  ! number of chebychev polynomials
    integer,   optional, intent(out) :: prefr  ! number of real refractive indices in table
    integer,   optional, intent(out) :: prefi  ! number of imaginary refractive indices in table

    ! hygrowghtpct table parameters
    real(r8),  optional, pointer     :: sw_hygro_ext_wtp(:,:) ! short wave extinction table
    real(r8),  optional, pointer     :: sw_hygro_ssa_wtp(:,:) ! short wave single-scatter albedo table
    real(r8),  optional, pointer     :: sw_hygro_asm_wtp(:,:) ! short wave asymmetry table
    real(r8),  optional, pointer     :: lw_hygro_ext_wtp(:,:) ! long wave absorption table
    real(r8),  optional, pointer     :: wgtpct(:)   ! weight precent of H2SO4/H2O solution
    integer,   optional, intent(out) :: nwtp        ! number of weight precent values

    ! hygrocoreshell table parameters
    real(r8),  optional, pointer     :: sw_hygro_coreshell_ext(:,:,:,:,:) ! short wave extinction table
    real(r8),  optional, pointer     :: sw_hygro_coreshell_ssa(:,:,:,:,:) ! short wave single-scatter albedo table
    real(r8),  optional, pointer     :: sw_hygro_coreshell_asm(:,:,:,:,:) ! short wave asymmetry table
    real(r8),  optional, pointer     :: lw_hygro_coreshell_ext(:,:,:,:,:) ! long wave absorption table
    real(r8),  optional, pointer     :: corefrac(:) ! core fraction dimension values
    real(r8),  optional, pointer     :: bcdust(:)   ! bc/(bc + dust) fraction dimension values
    real(r8),  optional, pointer     :: kap(:)      ! hygroscopicity dimension values
    real(r8),  optional, pointer     :: relh(:)     ! relative humidity dimension values
    integer,   optional, intent(out) :: nfrac       ! core fraction dimension size
    integer,   optional, intent(out) :: nbcdust     ! bc/(bc + dust) fraction dimension size
    integer,   optional, intent(out) :: nkap        ! hygroscopicity dimension size
    integer,   optional, intent(out) :: nrelh       ! relative humidity dimension size

    ! refactive index table parameters
    call rad_cnst_get_mode_props(list_ndx, bin_ndx, &
                                 opticstype=opticstype, &
                                 extpsw=extpsw, &
                                 abspsw=abspsw, &
                                 asmpsw=asmpsw, &
                                 absplw=absplw, &
                                 refrtabsw=refrtabsw, &
                                 refitabsw=refitabsw, &
                                 refrtablw=refrtablw, &
                                 refitablw=refitablw, &
                                 ncoef=ncoef, &
                                 prefr=prefr, &
                                 prefi=prefi)

    ! hygrowghtpct table parameters
    if (present(sw_hygro_ext_wtp)) then
       nullify(sw_hygro_ext_wtp)
    end if
    if (present(sw_hygro_ssa_wtp)) then
       nullify(sw_hygro_ssa_wtp)
    end if
    if (present(sw_hygro_asm_wtp)) then
       nullify(sw_hygro_asm_wtp)
    end if
    if (present(lw_hygro_ext_wtp)) then
       nullify(lw_hygro_ext_wtp)
    end if
    if (present(wgtpct)) then
       nullify(wgtpct)
    end if
    if (present(nwtp)) then
       nwtp = -1
    end if

    ! hygrocoreshell table parameters
    if (present(sw_hygro_coreshell_ext)) then
       nullify(sw_hygro_coreshell_ext)
    end if
    if (present(sw_hygro_coreshell_ssa)) then
       nullify(sw_hygro_coreshell_ssa)
    end if
    if (present(sw_hygro_coreshell_asm)) then
       nullify(sw_hygro_coreshell_asm)
    end if
    if (present(lw_hygro_coreshell_ext)) then
       nullify(lw_hygro_coreshell_ext)
    end if
    if (present(corefrac)) then
       nullify(corefrac)
    end if
    if (present(bcdust)) then
       nullify(bcdust)
    end if
    if (present(kap)) then
       nullify(kap)
    end if
    if (present(relh)) then
       nullify(relh)
    end if
    if (present(nfrac)) then
       nfrac = -1
    end if
    if (present(nbcdust)) then
       nbcdust = -1
    end if
    if (present(nkap)) then
       nkap = -1
    end if
    if (present(nrelh)) then
       nrelh = -1
    end if

  end subroutine optics_params

  !------------------------------------------------------------------------------
  ! returns radius^3 (m3) of a given bin number
  !------------------------------------------------------------------------------
  pure elemental real(r8) function amcube(self, bin_ndx, volconc, numconc)

    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx  ! bin number
    real(r8), intent(in) :: volconc ! volume conc (m3/m3)
    real(r8), intent(in) :: numconc ! number conc (1/m3)

    amcube = (3._r8*volconc/(4._r8*pi*self%exp45logsig_(bin_ndx)*numconc))

  end function amcube

  !------------------------------------------------------------------------------
  ! returns mass and number activation fractions
  !------------------------------------------------------------------------------
  subroutine actfracs(self, bin_ndx, smc, smax, fn, fm )
    use shr_spfn_mod, only: erf => shr_spfn_erf
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx   ! bin index
    real(r8),intent(in) :: smc       ! critical supersaturation for particles of bin radius
    real(r8),intent(in) :: smax      ! maximum supersaturation for multiple competing aerosols
    real(r8),intent(out) :: fn       ! activation fraction for aerosol number
    real(r8),intent(out) :: fm       ! activation fraction for aerosol mass

    real(r8) :: x,y
    real(r8), parameter :: twothird = 2._r8/3._r8
    real(r8), parameter :: sq2      = sqrt(2._r8)

    x=twothird*(log(smc)-log(smax))/(sq2*self%alogsig(bin_ndx))
    y=x-1.5_r8*sq2*self%alogsig(bin_ndx)

    fn = 0.5_r8*(1._r8-erf(x))
    fm = 0.5_r8*(1._r8-erf(y))

  end subroutine actfracs

  !------------------------------------------------------------------------
  ! returns constituents names of aerosol number mixing ratios
  !------------------------------------------------------------------------
  subroutine num_names(self, bin_ndx, name_a, name_c)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    character(len=*), intent(out) :: name_a ! constituent name of ambient aerosol number dens
    character(len=*), intent(out) :: name_c ! constituent name of cloud-borne aerosol number dens

    call rad_cnst_get_info(0,bin_ndx, num_name=name_a, num_name_cw=name_c)
  end subroutine num_names

  !------------------------------------------------------------------------
  ! returns constituents names of aerosol mass mixing ratios
  !------------------------------------------------------------------------
  subroutine mmr_names(self, bin_ndx, species_ndx, name_a, name_c)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    integer, intent(in) :: species_ndx       ! species number
    character(len=*), intent(out) :: name_a ! constituent name of ambient aerosol MMR
    character(len=*), intent(out) :: name_c ! constituent name of cloud-borne aerosol MMR

    call rad_cnst_get_info(0, bin_ndx, species_ndx, spec_name=name_a, spec_name_cw=name_c)
  end subroutine mmr_names

  !------------------------------------------------------------------------
  ! returns constituent name of ambient aerosol number mixing ratios
  !------------------------------------------------------------------------
  subroutine amb_num_name(self, bin_ndx, name)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    character(len=*), intent(out) :: name   ! constituent name of ambient aerosol number dens

    call rad_cnst_get_info(0,bin_ndx, num_name=name)

  end subroutine amb_num_name

  !------------------------------------------------------------------------
  ! returns constituent name of ambient aerosol mass mixing ratios
  !------------------------------------------------------------------------
  subroutine amb_mmr_name(self, bin_ndx, species_ndx, name)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    integer, intent(in) :: species_ndx       ! species number
    character(len=*), intent(out) :: name   ! constituent name of ambient aerosol MMR

    call rad_cnst_get_info(0, bin_ndx, species_ndx, spec_name=name)

  end subroutine amb_mmr_name

  !------------------------------------------------------------------------
  ! returns species type
  !------------------------------------------------------------------------
  subroutine species_type(self, bin_ndx, species_ndx, spectype)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    integer, intent(in) :: species_ndx       ! species number
    character(len=*), intent(out) :: spectype ! species type

    call rad_cnst_get_info(0, bin_ndx, species_ndx, spec_type=spectype)

  end subroutine species_type

  !------------------------------------------------------------------------------
  ! returns TRUE if Ice Nucleation tendencies are applied to given aerosol bin number
  !------------------------------------------------------------------------------
  function icenuc_updates_num(self, bin_ndx) result(res)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number

    logical :: res

    character(len=aero_name_len) :: spectype
    character(len=aero_name_len) :: modetype
    integer :: spc_ndx

    res = .false.

    call rad_cnst_get_info(0, bin_ndx, mode_type=modetype)
    if (.not.(modetype=='coarse' .or. modetype=='coarse_dust')) then
       return
    end if

    do spc_ndx = 1, self%nspecies(bin_ndx)
       call self%species_type( bin_ndx, spc_ndx, spectype)
       if (spectype=='dust') res = .true.
    end do

  end function icenuc_updates_num

  !------------------------------------------------------------------------------
  ! returns TRUE if Ice Nucleation tendencies are applied to a given species within a bin
  !------------------------------------------------------------------------------
  function icenuc_updates_mmr(self, bin_ndx, species_ndx) result(res)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    integer, intent(in) :: species_ndx       ! species number

    logical :: res

    character(len=32) :: spectype
    character(len=32) :: modetype

    res = .false.

    if (species_ndx>0) then

       call rad_cnst_get_info(0, bin_ndx, mode_type=modetype)
       if (.not.(modetype=='coarse' .or. modetype=='coarse_dust')) then
          return
       end if

       call self%species_type( bin_ndx, species_ndx, spectype)
       if (spectype=='dust') res = .true.
    end if

  end function icenuc_updates_mmr

  !------------------------------------------------------------------------------
  ! apply max / min to number concentration
  !------------------------------------------------------------------------------
  subroutine apply_number_limits( self, naerosol, vaerosol, istart, istop, m )
    class(modal_aerosol_properties), intent(in) :: self
    real(r8), intent(inout) :: naerosol(:)  ! number conc (1/m3)
    real(r8), intent(in)    :: vaerosol(:)  ! volume conc (m3/m3)
    integer,  intent(in) :: istart          ! start column index (1 <= istart <= istop <= pcols)
    integer,  intent(in) :: istop           ! stop column index
    integer,  intent(in) :: m               ! mode or bin index

    integer :: i

    ! adjust number so that dgnumlo < dgnum < dgnumhi
    ! -- the diameter falls within the lower and upper limits which are
    !    represented by voltonumhi and voltonumblo values, respectively
    do i = istart, istop
       naerosol(i) = max(naerosol(i), vaerosol(i)*self%voltonumbhi_(m))
       naerosol(i) = min(naerosol(i), vaerosol(i)*self%voltonumblo_(m))
    end do

  end subroutine apply_number_limits

  !------------------------------------------------------------------------------
  ! returns TRUE if species `spc_ndx` in aerosol subset `bin_ndx` contributes to
  ! the particles' ability to act as heterogeneous freezing nuclei
  !------------------------------------------------------------------------------
  function hetfrz_species(self, bin_ndx, spc_ndx) result(res)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx  ! bin number
    integer, intent(in) :: spc_ndx  ! species number

    logical :: res

    character(len=aero_name_len) :: mode_name, species_type

    res = .false.

    call rad_cnst_get_info(0, bin_ndx, mode_type=mode_name)

    if ((trim(mode_name)/='aitken')) then

       call self%species_type(bin_ndx, spc_ndx, species_type)

       if ((trim(species_type)=='black-c').or.(trim(species_type)=='dust')) then

          res = .true.

       end if

    end if

  end function hetfrz_species

  !------------------------------------------------------------------------------
  ! returns TRUE if soluble
  !------------------------------------------------------------------------------
  logical function soluble(self,bin_ndx)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number

    character(len=aero_name_len) :: mode_name

    call rad_cnst_get_info(0, bin_ndx, mode_type=mode_name)

    soluble = trim(mode_name)/='primary_carbon'

  end function soluble

  !------------------------------------------------------------------------------
  ! returns minimum mass mean radius (meters)
  !------------------------------------------------------------------------------
  function min_mass_mean_rad(self,bin_ndx,species_ndx) result(minrad)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx           ! bin number
    integer, intent(in) :: species_ndx       ! species number

    real(r8) :: minrad  ! meters

    integer :: nmodes
    character(len=aero_name_len) :: species_type, mode_type

    call self%species_type(bin_ndx, species_ndx, spectype=species_type)
    select case ( trim(species_type) )
    case('dust')
       call rad_cnst_get_info(0, bin_ndx, mode_type=mode_type)
       select case ( trim(mode_type) )
       case ('accum','fine_dust')
          minrad = 0.258e-6_r8
       case ('coarse','coarse_dust')
          minrad = 1.576e-6_r8
       case default
          minrad = -huge(1._r8)
       end select
    case('black-c')
       call rad_cnst_get_info(0, nmodes=nmodes)
       if (nmodes==3) then
          minrad = 0.04e-6_r8
       else
          minrad = 0.067e-6_r8 ! from emission size
       endif
    case default
       minrad = -huge(1._r8)
    end select

  end function min_mass_mean_rad

  !------------------------------------------------------------------------------
  ! returns the total number of bins for a given radiation list index
  !------------------------------------------------------------------------------
  function nbins_rlist(self, list_ndx)  result(res)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: list_ndx  ! radiation list number

    integer :: res

    call rad_cnst_get_info(list_ndx, nmodes=res)

  end function nbins_rlist

  !------------------------------------------------------------------------------
  ! returns number of species in a bin for a given radiation list index
  !------------------------------------------------------------------------------
  function nspecies_per_bin_rlist(self, list_ndx,  bin_ndx)  result(res)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: list_ndx ! radiation list number
    integer, intent(in) :: bin_ndx  ! bin number

    integer :: res

    call rad_cnst_get_info(list_ndx, bin_ndx, nspec=res)

  end function nspecies_per_bin_rlist

  !------------------------------------------------------------------------------
  ! returns the natural log of geometric standard deviation of the number
  ! distribution for radiation list number and aerosol bin
  !------------------------------------------------------------------------------
  function alogsig_rlist(self, list_ndx,  bin_ndx)  result(res)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: list_ndx ! radiation list number
    integer, intent(in) :: bin_ndx  ! bin number

    real(r8) :: res

    real(r8) :: sig

    call rad_cnst_get_mode_props(list_ndx, bin_ndx, sigmag=sig)
    res = log(sig)

  end function alogsig_rlist

  !------------------------------------------------------------------------------
  ! returns name for a given radiation list number and aerosol bin
  !------------------------------------------------------------------------------
  function bin_name(self, list_ndx,  bin_ndx) result(name)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: list_ndx ! radiation list number
    integer, intent(in) :: bin_ndx  ! bin number

    character(len=32) name

    call rad_cnst_get_info(list_ndx, bin_ndx, mode_type=name)

  end function bin_name

  !------------------------------------------------------------------------------
  ! returns scavenging diameter (cm) for a given aerosol bin number
  !------------------------------------------------------------------------------
  function scav_diam(self, bin_ndx) result(diam)
    use modal_aero_data, only: dgnum_amode

    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx  ! bin number

    real(r8) :: diam

    diam = dgnum_amode(bin_ndx)

  end function scav_diam

  !------------------------------------------------------------------------------
  ! adjust aerosol concentration tendencies to create larger sizes of aerosols
  ! during resuspension
  !------------------------------------------------------------------------------
  subroutine resuspension_resize(self, dcondt)

    use modal_aero_data, only:  mode_size_order

    class(modal_aerosol_properties), intent(in) :: self
    real(r8), intent(inout) :: dcondt(:)

    integer :: i
    character(len=4) :: spcstr

    call accumulate_to_larger_mode( 'SO4', self%sulfate_mode_ndxs_, dcondt )
    call accumulate_to_larger_mode( 'DUST',self%dust_mode_ndxs_,dcondt )
    call accumulate_to_larger_mode( 'NACL',self%ssalt_mode_ndxs_,dcondt )
    call accumulate_to_larger_mode( 'MSA', self%msa_mode_ndxs_, dcondt )
    call accumulate_to_larger_mode( 'NH4', self%ammon_mode_ndxs_, dcondt )
    call accumulate_to_larger_mode( 'NO3', self%nitrate_mode_ndxs_, dcondt )

    spcstr = '    '
    do i = 1,self%num_soa_
       write(spcstr,'(i4)') i
       call accumulate_to_larger_mode( 'SOA'//adjustl(spcstr), self%sorganic_mode_ndxs_(:,i), dcondt )
    enddo
    spcstr = '    '
    do i = 1,self%num_poa_
       write(spcstr,'(i4)') i
       call accumulate_to_larger_mode( 'POM'//adjustl(spcstr), self%porganic_mode_ndxs_(:,i), dcondt )
    enddo
    spcstr = '    '
    do i = 1,self%num_bc_
       write(spcstr,'(i4)') i
       call accumulate_to_larger_mode( 'BC'//adjustl(spcstr), self%bcarbon_mode_ndxs_(:,i), dcondt )
    enddo

  contains

    !------------------------------------------------------------------------------
    subroutine accumulate_to_larger_mode( spc_name, lptr, prevap )

      use cam_logfile, only: iulog
      use spmd_utils, only: masterproc

      character(len=*), intent(in) :: spc_name
      integer,  intent(in) :: lptr(:)
      real(r8), intent(inout) :: prevap(:)

      integer :: m,n, nl,ns

      logical, parameter :: debug = .false.

      ! find constituent index of the largest mode for the species
      loop1: do m = 1,self%nbins()-1
         nl = lptr(mode_size_order(m))
         if (nl>0) exit loop1
      end do loop1

      if (.not. nl>0) return

      ! accumulate the smaller modes into the largest mode
      do n = m+1,self%nbins()
         ns = lptr(mode_size_order(n))
         if (ns>0) then
            prevap(nl) = prevap(nl) + prevap(ns)
            prevap(ns) = 0._r8
            if (masterproc .and. debug) then
               write(iulog,'(a,i3,a,i3)') trim(spc_name)//' mode number accumulate ',ns,'->',nl
            endif
         endif
      end do

    end subroutine accumulate_to_larger_mode
    !------------------------------------------------------------------------------

  end subroutine resuspension_resize

  !------------------------------------------------------------------------------
  ! returns bulk deposition fluxes of the specified species type
  ! rebinned to specified diameter limits
  !------------------------------------------------------------------------------
  subroutine rebin_bulk_fluxes(self, bulk_type, dep_fluxes, diam_edges, bulk_fluxes, &
                               error_code, error_string)
    use infnan, only: nan, assignment(=)

    class(modal_aerosol_properties), intent(in) :: self
    character(len=*),intent(in) :: bulk_type       ! aerosol type to rebin
    real(r8), intent(in) :: dep_fluxes(:)          ! kg/m2
    real(r8), intent(in) :: diam_edges(:)          ! meters
    real(r8), intent(out) :: bulk_fluxes(:)        ! kg/m2
    integer,  intent(out) :: error_code            ! error code (0 if no error)
    character(len=*), intent(out) :: error_string  ! error string

    real(r8) :: dns_dst ! kg/m3
    real(r8) :: sigma_g, vmd, tmp, massfrac_bin(size(bulk_fluxes))
    real(r8) :: Ntype, Mtype, Mtotal, Ntot
    integer :: k,l,m,mm, nbulk
    logical :: has_type, type_not_found

    character(len=aero_name_len) :: spectype
    character(len=aero_name_len) :: modetype

    real(r8), parameter :: sqrtwo = sqrt(2._r8)
    real(r8), parameter :: onethrd = 1._r8/3._r8

    error_code = 0
    error_string = ' '

    type_not_found = .true.

    nbulk = size(bulk_fluxes)

    bulk_fluxes(:) = 0.0_r8

    do m = 1,self%nbins()
       Mtype = 0._r8
       Mtotal = 0._r8
       mm = self%indexer(m,0)
       Ntot = dep_fluxes(mm) ! #/m2

       has_type = .false.

       do l = 1,self%nspecies(m)
          mm = self%indexer(m,l)
          call self%get(m,l, spectype=spectype, density=dns_dst) ! kg/m3
          if (spectype==bulk_type) then
             Mtype = dep_fluxes(mm) ! kg/m2
             has_type = .true.
             type_not_found = .false.
          end if
          Mtotal = Mtotal + dep_fluxes(mm) ! kg/m2
       end do
       mode_has_type: if (has_type) then
          call rad_cnst_get_info(0, m, mode_type=modetype)
          if (Ntot>1.e-40_r8 .and. Mtype>1.e-40_r8 .and. Mtotal>1.e-40_r8) then

             call rad_cnst_get_mode_props(0, m, sigmag=sigma_g)
             tmp = sqrtwo*log(sigma_g)

             ! type number concentration
             Ntype = Ntot * Mtype/Mtotal ! #/m2

             ! volume median diameter (meters)
             vmd = (6._r8*Mtype/(pi*Ntype*dns_dst))**onethrd * exp(1.5_r8*(log(sigma_g))**2)

             massfrac_bin = 0._r8

             do k = 1,nbulk
                massfrac_bin(k) = 0.5_r8*( erf((log(diam_edges(k+1)/vmd))/tmp) &
                                - erf((log(diam_edges(k  )/vmd))/tmp) )
                bulk_fluxes(k) = bulk_fluxes(k) + massfrac_bin(k) * Mtype
             end do

             if (debug) then
                if (abs(1._r8-sum(massfrac_bin)) > 1.e-6_r8) then
                   write(*,*) 'rebin_bulk_fluxes WARNING mode-num, massfrac_bin, sum(massfrac_bin) = ', &
                        m, massfrac_bin, sum(massfrac_bin)
                end if
             end if

          end if
       end if mode_has_type
    end do

    if (type_not_found) then
       bulk_fluxes(:) = nan
       error_code = 1
       write(error_string,*) 'aerosol_properties::rebin_bulk_fluxes ERROR : ',trim(bulk_type),' not found'
    end if

  end subroutine rebin_bulk_fluxes

  !------------------------------------------------------------------------------
  ! Returns TRUE if bin is hydrophilic, otherwise FALSE
  !------------------------------------------------------------------------------
  logical function hydrophilic(self, bin_ndx)
    class(modal_aerosol_properties), intent(in) :: self
    integer, intent(in) :: bin_ndx ! bin number

    character(len=aero_name_len) :: modetype

    call rad_cnst_get_info(0, bin_ndx, mode_type=modetype)

    hydrophilic = (trim(modetype) == 'accum')

  end function hydrophilic

end module modal_aerosol_properties_mod
